# S3 decoupling

## Phase 1 - preparation

Rename the product surfaces around the new model (1-2h). Make Processing the first/default settings area, rename Storage to Advanced Pipeline, and change all S3 copy to Mirror originals to S3.

Add a single Bucket Mirroring toggle (2-3h). Make it off by default (S3 fields are still configurable, but users should see a short info text informing them they only take into effect when the switch is on).

Split validation rules by concern (2h). Local should require nothing extra, Cloud should require only the Mistral key, and S3 credentials should only be required when mirroring is on.

## Phase 2 - direct upload

Add the Cloud + no S3 route (3-4h). Make cloud processing work directly against Mistral when bucket mirroring is off.

## Phase 3 - s3 mirror cut off

Make S3 mirroring independent of processing (3-4h). Support Local + mirroring and Cloud + mirroring as valid combinations.

Make mirroring best-effort, not a hard precondition (2-3h). Processing should still complete if the optional mirror step fails, with a clear warning instead of a full job failure.

## Phase 4 - several UI improvements

Split job feedback into separate stages (2-3h). Show processing, mirroring, and delivery as distinct statuses so users understand what failed.

Add a compact pipeline summary in the UI (1-2h). Something like Cloud processing • S3 mirroring off • Save to ~/Documents/trnscrb reduces configuration ambiguity.

Final pass on wording naming conventions etc. also in code. it should be aligned with Product model
