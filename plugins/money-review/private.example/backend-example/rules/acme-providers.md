# Acme providers (ACME)

Facts about our providers and flows that the code does not show. Each rule names the
incident or data check it comes from.

## ACME-1. Provider X ignores a billing cycle it did not create

Source: incident of 2026-03-14, 212 retention discounts never applied.

Provider X keeps the billing cycle a subscription was created with. A modify request
with another cycle is answered with 200 and does nothing.

Look for: a modify, discount or retention request to provider X that builds the cycle
from current settings instead of the subscription's own; a discount recorded as applied
on the response alone.

Failure scenario: the user accepts 50% off, the request goes with a monthly cycle for a
subscription created with a 30-day one, X answers 200, we record the discount; the next
renewal charges the full price and the user files a chargeback.

Good: the cycle comes from the subscription; the discount is applied when the next
renewal amount at X shows it (PSP-1).

Do not report: requests that read the cycle from the subscription.
