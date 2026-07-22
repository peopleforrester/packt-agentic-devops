#!/usr/bin/env python3
# ABOUTME: Adds the router's wildcard DNS records to ai-enhanced-devops.com, preserving every
# ABOUTME: existing record, because Namecheap's setHosts replaces the entire zone in one call.
#
# The zone carries live workshop email (Resend DKIM, SPF, DMARC, an SES MX) and the claim app's
# own CNAME. setHosts is not additive: anything omitted from the call is deleted. So this reads
# the current zone, adds only what is missing, and refuses to run if a record it would preserve
# looks wrong. Run with --apply to execute; the default prints the diff and changes nothing.
import argparse
import os
import re
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

API = "https://api.namecheap.com/xml.response"
SLD, TLD = "ai-enhanced-devops", "com"

# The records the router needs. Values come from `railway domain "*.packt.ai-enhanced-devops.com"`.
# All three are required or the wildcard certificate never issues.
WANTED = [
    ("CNAME", "*.packt", "6csk7bl6.up.railway.app."),
    ("CNAME", "_acme-challenge.packt", "6csk7bl6.authorize.railwaydns.net."),
    ("TXT", "_railway-verify.packt",
     "railway-verify=3b7a66f88e44c2ac5e50cacb0205db7a9f7c32b9f2480d24ec08d23a9a61a14a"),
]


def creds():
    env = os.path.expanduser("~/secrets/dns/namecheap.env")
    out = {}
    with open(env, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip().strip('"').strip("'")
    ip = urllib.request.urlopen("https://api.ipify.org", timeout=15).read().decode()
    return out, ip


def call(params, post=False):
    if post:
        data = urllib.parse.urlencode(params).encode()
        req = urllib.request.Request(API, data=data)
    else:
        req = urllib.request.Request(API + "?" + urllib.parse.urlencode(params))
    body = urllib.request.urlopen(req, timeout=60).read().decode()
    root = ET.fromstring(re.sub(r'\sxmlns="[^"]+"', "", body))
    if root.get("Status") != "OK":
        for err in root.iter("Error"):
            sys.exit(f"Namecheap API error: {err.text}")
        sys.exit(f"Namecheap API returned Status={root.get('Status')}")
    return root


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="execute the change (default: diff only)")
    args = ap.parse_args()

    c, ip = creds()
    base = {
        "ApiUser": c["NAMECHEAP_API_USER"],
        "ApiKey": c["NAMECHEAP_API_KEY"],
        "UserName": c["NAMECHEAP_USERNAME"],
        # Must match the IP the call actually comes from, not whatever the env file was last set to.
        "ClientIp": ip,
    }

    root = call({**base, "Command": "namecheap.domains.dns.getHosts", "SLD": SLD, "TLD": TLD})
    result = root.find(".//DomainDNSGetHostsResult")
    email_type = result.get("EmailType")
    existing = [
        (h.get("Type"), h.get("Name"), h.get("Address"), h.get("TTL"), h.get("MXPref"))
        for h in root.iter("host")
    ]
    print(f"Read {len(existing)} existing records (EmailType={email_type})")

    # Guard: the zone must still look like the one we backed up. If the live zone has fewer records
    # than the things we know must be there, something else changed it and a blind rewrite is unsafe.
    must_keep = {"resend._domainkey", "send", "_dmarc", "packt", "*"}
    present = {n for _, n, _, _, _ in existing}
    missing = must_keep - present
    if missing:
        sys.exit(f"REFUSING: live zone is missing records we expected to preserve: {sorted(missing)}")

    final = list(existing)
    added = []
    for rtype, name, addr in WANTED:
        match = [e for e in existing if e[0] == rtype and e[1] == name]
        if match:
            if match[0][2] != addr:
                sys.exit(
                    f"REFUSING: {rtype} {name} exists with a different value.\n"
                    f"  live:   {match[0][2]}\n  wanted: {addr}\n"
                    "Resolve by hand; overwriting a record we did not create is not safe."
                )
            print(f"  = {rtype:5} {name:24} already correct")
            continue
        final.append((rtype, name, addr, "300", "10"))
        added.append((rtype, name, addr))
        print(f"  + {rtype:5} {name:24} {addr}")

    if not added:
        print("\nNothing to add; DNS already correct.")
        return

    print(f"\n{len(existing)} preserved, {len(added)} added, 0 removed -> {len(final)} total")
    if not args.apply:
        print("Dry run. Re-run with --apply to execute.")
        return

    params = {**base, "Command": "namecheap.domains.dns.setHosts", "SLD": SLD, "TLD": TLD,
              "EmailType": email_type}
    for i, (rtype, name, addr, ttl, mxpref) in enumerate(final, start=1):
        params[f"HostName{i}"] = name
        params[f"RecordType{i}"] = rtype
        params[f"Address{i}"] = addr
        params[f"TTL{i}"] = ttl
        if rtype == "MX":
            params[f"MXPref{i}"] = mxpref
    out = call(params, post=True)
    res = out.find(".//DomainDNSSetHostsResult")
    print(f"setHosts IsSuccess={res.get('IsSuccess')}")

    verify = call({**base, "Command": "namecheap.domains.dns.getHosts", "SLD": SLD, "TLD": TLD})
    now = [(h.get("Type"), h.get("Name")) for h in verify.iter("host")]
    print(f"Zone now has {len(now)} records")
    for rtype, name, _ in WANTED:
        status = "OK" if (rtype, name) in now else "MISSING"
        print(f"  {status:8} {rtype} {name}")


if __name__ == "__main__":
    main()
