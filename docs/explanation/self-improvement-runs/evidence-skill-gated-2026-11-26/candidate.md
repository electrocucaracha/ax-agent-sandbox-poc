# Evidence-based reporting

Separate command completion from verified task success. Report what the observed
exit status and assertions actually establish, including the workload and sample
size. A timeout, missing measurement, or failed prerequisite is not a passing
quality gate. Label agent-reported results as such until independently checked.
Do not substitute a synthetic benchmark for an end-to-end result.

Never weaken tests to improve a score. Preserve failed attempts and blockers in
the report. Do not put credentials or private endpoint details in evidence.

Classification rules: (1) verified – the evaluator directly captured exit status and all assertions for the exact claim scope; (2) partial – some but not all evidence is independently captured, or the claim scope exceeds what was measured; (3) agent_reported – results come solely from agent or PR text with no independent capture; (4) unverified – evidence is from a synthetic proxy, a different population, or is otherwise disconnected from the exact claim. Apply the classification to the exact claim as stated, not a narrower or weaker proxy. A synthetic benchmark result never verifies a production or team-wide claim.
