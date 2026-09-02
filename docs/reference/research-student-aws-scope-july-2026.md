# Student AWS permission scope on a workshop cluster

Research spike, 2026-07-21. Question: are the student terminal's AWS permissions scoped
correctly for the Packt workshop? Not so wide that a student can attack anything or run
unrelated AWS services, not so narrow that the workshop is blocked.

Findings marked VERIFIED were tested on the live `adwc-dev` cluster in account
515966504359 on 2026-07-21. Findings marked SOURCED cite upstream policy or docs.

## Answer in short

The terminal's own role is correctly scoped and should stay as it is. It does not need to
change. But the terminal's own role is not what determines the student's AWS reach, and
that is the finding worth knowing before the workshop.

## 1. Controllers carry their own roles, so the student role can stay tiny

VERIFIED. `adwc-dev` had exactly two pod identity associations before this work, both
created by terraform:

| Namespace | ServiceAccount | Purpose |
|---|---|---|
| kube-system | aws-load-balancer-controller | provisions the NLB for the VTT Service |
| kube-system | ebs-csi-controller-sa | provisions gp3 volumes |

Provisioning adds a third, `workshop/web-terminal`, scoped to `eks:DescribeCluster` on its
own cluster ARN plus `eks:ListClusters`.

Because the controllers hold their own roles, nothing the workshop installs depends on the
student's role being wide. Keeping it at describe-my-own-cluster blocks nothing.

## 2. Karpenter is not deployed, so nobody can launch compute

VERIFIED and SOURCED to the repo. `internal/build-spec.md` excludes Karpenter twice:
"Self-managed Karpenter is not used: for 300 fixed-shape, short-lived clusters it adds a
per-cluster controller for no benefit. Managed node groups carry the node layout." A
second entry rejects per-cluster Karpenter for adding 1 to 2 minutes of live node spin-up
inside a timed beat.

Consequence: no role on a student cluster holds `ec2:RunInstances` or `iam:PassRole`. A
student cannot start another node. The node group is a fixed shape set at provisioning.
The concern that "Karpenter is going to need something" does not apply to this build.

## 3. Cluster-admin makes the student's reach the union of all pod identity roles

VERIFIED, and this is the crux.

EKS Pod Identity resolves credentials by the tuple (cluster, namespace, ServiceAccount).
It does not verify which workload is using the ServiceAccount. The student is cluster-admin
on their own cluster by design, because installing the platform requires creating CRDs,
ClusterRoles, and ClusterRoleBindings. A cluster-admin can therefore schedule a pod that
uses any ServiceAccount in any namespace, including one that has an association.

Tested directly. A pod created in `kube-system` with
`serviceAccountName: aws-load-balancer-controller` received:

```
arn:aws:sts::515966504359:assumed-role/adwc-dev-aws-lbc-b26fc4da074f6a8355296c8ff6/eks-adwc-dev-podid-esca-...
```

So the student's effective AWS reach is the union of every pod identity role on their
cluster. Tightening the terminal's own role does not reduce that union. There is no
Pod Identity setting that prevents it; the mechanism is working as documented.

The Datadog analysis of Pod Identity reaches the same conclusion for the general case: an
attacker who reaches cluster-admin can impersonate the ServiceAccount of any pod and
obtain its cloud identity.

## 4. The load balancer controller policy reaches beyond the cluster

VERIFIED on the deployed policy and SOURCED to the upstream policy AWS ships.

The upstream `iam_policy.json` does scope its most destructive calls by tag. Statements
covering `DeleteLoadBalancer`, `DeleteTargetGroup`, and load balancer attribute changes
carry `aws:ResourceTag/elbv2.k8s.aws/cluster` or `elasticloadbalancing:CreateAction`
conditions, so one cluster's controller cannot delete another cluster's load balancer.

These statements do not. They are `Resource: "*"` with no `Condition` at all:

| Actions | Statement |
|---|---|
| `ec2:CreateSecurityGroup` | 5 |
| `ec2:AuthorizeSecurityGroupIngress`, `ec2:RevokeSecurityGroupIngress` | 4 |
| `elasticloadbalancing:CreateListener`, `DeleteListener`, `CreateRule`, `DeleteRule` | 10 |
| `elasticloadbalancing:ModifyListener`, `ModifyRule`, `SetRulePriorities`, `SetWebAcl`, `AddListenerCertificates`, `RemoveListenerCertificates` | 15 |

Listeners and rules are child resources of a load balancer, and the tag conditions that
protect the parent do not extend to them. With roughly 50 student clusters per AWS account,
a student who deliberately assumes this role can delete listeners on another student's NLB
and take their terminal offline, and can revoke security group ingress account-wide.

The containment boundary is the AWS account, not intra-cluster RBAC.

## 5. Node credentials are a lesser path

VERIFIED. Node IMDS is already hardened: `HttpPutResponseHopLimit` is 1 and `HttpTokens` is
`required`, so an ordinary pod cannot reach IMDS. A `hostNetwork` pod still can, and a
cluster-admin can create one. What it yields is limited: the node role carries only
`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, and `AmazonEC2ContainerRegistryReadOnly`.
No compute launch, no IAM. This path is not worth mitigating for this event.

## 6. What the workshop actually asks a student to run

The workshop is a Kubernetes and GitOps build. The student's agent works through `kubectl`,
`helm`, `argocd`, and `git` against the in-cluster Gitea. AWS CLI calls are incidental:
confirming identity and confirming the cluster is reachable. `eks:DescribeCluster` plus
`eks:ListClusters` covers that. No phase requires an AWS mutation from the student's shell,
because every AWS resource the platform needs (the NLB, the EBS volumes) is created by a
controller using the controller's own role.

Conclusion: do not widen the terminal role.

## Recommendation

Ranked by risk reduced against risk added, two days before the event.

**Do now: nothing to the IAM configuration.** The terminal role is correct. Every candidate
tightening touches something the live build depends on.

**Do not attempt before the workshop:**

- Editing the load balancer controller policy to add tag conditions on listeners and rules.
  The controller creates and deletes listeners whenever a student creates or deletes a
  Service, which the workshop does repeatedly. A wrong condition breaks the build on all
  250 clusters and the failure appears mid-workshop, not at provisioning.
- An SCP denying `elasticloadbalancing:Delete*`. Same objection. The controller legitimately
  issues those calls during normal operation.
- Blocking the escalation with a Kyverno policy on ServiceAccount use in `kube-system`. The
  student is cluster-admin and can delete the policy, so it raises the bar without setting
  one, and it risks interfering with legitimate controller pods.

**Worth doing, low cost, after the event or in the fleet driver:**

- Keep teardown tag-driven and complete, so griefing is recoverable by rebuilding rather
  than by manual repair.
- If the fleet ever moves to fewer students per account, the blast radius shrinks with it.
  This is the only structural fix, and it is an account-topology decision, not an IAM one.

**Accepted risk for July 23 2026.** Reaching the escalation requires deliberately creating
a pod with a specific ServiceAccount in a specific namespace. No workshop instruction goes
near it. Attendees are paying customers in a three-hour session on disposable clusters. The
realistic failure is one curious attendee knocking another attendee's terminal offline, and
the recovery is a reprovision.

## Sources

- [aws-load-balancer-controller iam_policy.json](https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json): the statement-by-statement condition analysis in section 4.
- [Learn how EKS Pod Identity grants pods access to AWS services](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html): association is per (namespace, ServiceAccount); any pod using that ServiceAccount gets the role.
- [Deep dive into the new Amazon EKS Pod Identity feature, Datadog Security Labs](https://securitylabs.datadoghq.com/articles/eks-pod-identity-deep-dive/): independent analysis of the mechanism.
- [Attacking and securing cloud identities in managed Kubernetes: Amazon EKS, Datadog Security Labs](https://securitylabs.datadoghq.com/articles/amazon-eks-attacking-securing-cloud-identities/): cluster-admin to ServiceAccount impersonation to cloud identity.
- [EKS Best Practices Guide, Identity and Access Management](https://aws.github.io/aws-eks-best-practices/security/docs/iam/): AWS guidance on scoping.
