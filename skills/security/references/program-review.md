# Program review

Load this file in program mode only. It holds the checklists for a review of a
whole product against a named standard. The route keeps the rules. This file
keeps the lists.

## 1. Pin the review

Record the commit of each branch that you read, and the date. Repeat this line in
every issue that you write.

## 2. Threat sentence

Write one sentence, taken from the product and its data. Example: "A public
directory by social cause, with location. The threat is abuse by groups,
unavailability, reputation manipulation and persecution of participants." The
sentence is an example. Derive your own from the target.

## 3. Coverage table

Give one row for each category of OWASP Top 10:2025. The columns are id, category,
status, evidence and route.

| Id | Category |
| --- | --- |
| A01 | Broken Access Control |
| A02 | Security Misconfiguration |
| A03 | Software Supply Chain Failures |
| A04 | Cryptographic Failures |
| A05 | Injection |
| A06 | Insecure Design |
| A07 | Authentication Failures |
| A08 | Software or Data Integrity Failures |
| A09 | Security Logging and Alerting Failures |
| A10 | Mishandling of Exceptional Conditions |

The names come from https://top10.owasp.org/2025. Use one status for each row:
`checked`, `not checked`, or `out of scope: <reason>`. A row that needs a provider
fact (hosting, database, firewall, backups) is `not checked`. Name the missing
fact. Add a note with file and line to each positive finding, for example salted
password hashing.

## 4. Harm-to-people checklist

- Hostile or false content about a named person or business.
- Mass reports used as a weapon. Mass reports that take down content on their own.
- Impersonation through claim flows.
- Doxxing through public owner or contact data.
- Brigading and quota abuse that hides content.
- Moderator tools. They must be reversible, give a reason and write a log.
- The suspension model for accounts.

For each item, name the lower-trust principal, the action, the affected person and
the visible result.

## 5. Privacy pass

Every legal point below needs an official source and the line "not reviewed by a
lawyer". Record gaps. Do not conclude that an infraction, an incident or an unseen
contract exists.

1. Applicability. LGPD articles 3 and 4 apply. Data about a natural person is in
   scope, also for an open source or non-profit target. Public data is not out of
   scope by default.
2. Inventory. For each processing, record purpose, data categories, source,
   subjects, recipients, legal basis, necessity, duration and owner.
3. Notice. Compare the privacy notice with the real processing.
4. Legal basis. Name one basis for each purpose. Do not use one blanket consent.
5. Controller and contact channel. If you cannot see them, record a gap. Do not
   assume them.
6. Rights channel. Articles 18 to 20. Test the channel in the real interface and
   documents.
7. Retention. Check expired sessions, soft-deleted text, free text in the audit
   log, orphan media and backups.
8. Third-party scripts and consent. One unauthenticated GET shows only the
   published reference. It does not show which events reach the vendor. State this
   limit.
9. Vendors and international transfers. List them. If the contracts are not
   visible, write "verification task", not "violation".
10. Sensitive data, article 11. Do not assume that a field is sensitive. Say why it
    could be.

## 6. Detection and response checklist

- Audit-log completeness and atomicity.
- Alerts on abuse signals.
- Log redaction. Logs must not hold passwords, tokens, cookies or request bodies.
- A failure of the log collector must not block login.
- The report channel (`SECURITY.md` or an equivalent).
- The incident procedure, and a drill with synthetic data.
- Secret rotation.
- A backup restore that applies the deletions again.

## 7. Rating rubric

Use the route's [Ratings](../SKILL.md#ratings) policy.

Contextual priority:

- P1: people can be harmed now, and a fix has a bounded size.
- P2: a real gap, and the harm can wait.
- P3: hygiene.

Score three inputs on low, medium or high: likelihood, impact on people and
effort. Write the three values next to the priority. Do not give P1 to an item that
needs no change.

## 8. Output shape

Write one tracking issue, and one action issue for each theme.

- Tracker: scope and threat, the table, the proposed order, limits and completion
  criteria.
- Action issue: a fixed header (commits, type, priority, context, OWASP ids,
  "preventive, no incident observed"). Then "Problem and evidence" with file and
  line. Then "Expected result" as outcome checkboxes. Name the property, not the
  steps. End with one cheat-sheet reference.
- Each action issue has a test criterion with synthetic data, a documentation
  criterion and a "do not" guard.
- Write the boundary with existing issues in prose, and link them. Do not copy
  them.
- A legal follow-up adds criteria to the same issue as a comment.
- Use the issue types and labels of the target repository. If you cannot triage,
  say so in the tracker and name who applies the labels.
- Name an owner for the triage of private reports.
- If a privacy series exists, link it in the completion criteria of the tracker.

Filing an issue is a write to a shared place. It needs its own authority.

## 9. Limits list (mandatory)

Say what you did not do. Write each item that applies:

- no scan
- no exploit
- no load test
- no production data
- no provider panel
- no firewall rules
- no restore test
- no database grants
- no history scan for secrets
- no real HTTP behavior

Add anything else that you did not do.

## 10. Disclosure

Follow [Disclosure](../SKILL.md#disclosure) and
[Duplicate checks](../SKILL.md#duplicate-checks) in the route.
