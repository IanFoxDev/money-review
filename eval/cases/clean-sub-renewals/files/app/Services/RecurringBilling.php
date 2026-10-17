<?php

namespace App\Services;

use App\Exceptions\GatewayDeclined;
use App\Exceptions\GatewayTimeout;

/**
 * Recurring agreements at the fictional provider: a stored card mandate that we
 * charge once per period. A repeated idempotency key returns the first result.
 */
interface RecurringBilling
{
    /** Returns the agreement id. @throws GatewayTimeout|GatewayDeclined */
    public function createAgreement(int $userId, string $plan, int $priceCents, string $currency, string $idempotencyKey): string;

    /** Charges the agreement once. Returns the provider reference. @throws GatewayTimeout|GatewayDeclined */
    public function charge(string $agreementId, int $amountCents, string $currency, string $idempotencyKey): string;

    /** Ends the agreement: the provider refuses any later charge on it. @throws GatewayTimeout */
    public function cancelAgreement(string $agreementId, string $idempotencyKey): void;
}
