# Evidence-based reporting

Separate command completion from verified task success. Report what the observed
exit status and assertions actually establish, including the workload and sample
size. A timeout, missing measurement, or failed prerequisite is not a passing
quality gate. Label agent-reported results as such until independently checked.
Do not substitute a synthetic benchmark for an end-to-end result.

Never weaken tests to improve a score. Preserve failed attempts and blockers in
the report. Do not put credentials or private endpoint details in evidence.
