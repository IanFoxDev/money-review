<?php

namespace App\Services;

use App\Exceptions\GatewayDeclined;
use App\Exceptions\GatewayTimeout;

/**
 * Fictional payment provider. Every call that moves money takes an idempotency
 * key: the provider returns the first result for a repeated key.
 */
interface PaymentGateway
{
    /** @throws GatewayTimeout|GatewayDeclined */
    public function refund(string $pspReference, int $amountCents, string $currency, string $idempotencyKey): string;

    /** @throws GatewayTimeout|GatewayDeclined */
    public function payout(int $partnerId, int $amountCents, string $currency, string $idempotencyKey): string;

    /** Current state of an operation by our idempotency key: succeeded, failed or unknown. */
    public function status(string $idempotencyKey): string;
}
