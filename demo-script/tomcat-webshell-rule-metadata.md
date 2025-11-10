# Tomcat Manager Web Shell Deployment - Rule Metadata

Use this metadata when creating the rule in Kibana UI (Local instance).

## Basic Information

**Name:** Tomcat Manager Web Shell Deployment

**Description:**
```
Detects web shell deployment via Apache Tomcat Manager interface.
Identifies when the Tomcat Java process spawns shell interpreters,
indicating potential exploitation of weak credentials or vulnerabilities.
```

**Severity:** High

**Risk Score:** 73

## Rule Configuration

**Rule Type:** Event Correlation (EQL)

**Index Pattern:** `logs-endpoint.events.*`

**Query:** (see tomcat-webshell-rule-query.eql)

**Runs every:** 5 minutes

**Looks back:** 9 minutes (`from = "now-9m"`)

**Maximum signals per execution:** 100

## Tags

- Domain: Endpoint
- OS: Linux
- Use Case: Threat Detection
- Tactic: Initial Access
- Tactic: Execution
- Data Source: Elastic Defend

## MITRE ATT&CK Mapping

**Tactic:** Initial Access (TA0001)

**Techniques:**
- T1190: Exploit Public-Facing Application
- T1505: Server Software Component
  - T1505.003: Web Shell

## Additional Settings

**Timestamp override:** event.ingested

**Author:** Elastic, [Your Name]

**License:** Elastic License v2

**Maturity:** Production
