## Background

Try to route the external https traffic to a mock service.

For example, we have a foo service needs to call https://slack.com

This is the production route traffic:

```
+---------+      https      +---------+
|   foo   |  ------------>  |  Slack  |
+---------+                 +---------+
```

How to use egress gateway to transfer the external https to a mock service?

we Have a mock service, this is what we want to:

```
+---------+      https      +---------+
|   foo   |  ------------>  |  mock   |
+---------+                 +---------+
```

## 📢 Help ME!

I don't find a solution, please share you comments or PR directly.

I make this repository as the basic experimental playground, you can run in any environment. 

I tried to add a extra proxy on mock, or enable mTLS on the mock, they didn't work.

## Test

setup everything

```
make setup
```

test an request

```
make try
```

check the foo log

```
kubectl logs -l app=foo -f
```

check the mock log

```
kubectl logs -l app=mock -f
```

if you changed something, run:

```
make reploy
```

then try again!

