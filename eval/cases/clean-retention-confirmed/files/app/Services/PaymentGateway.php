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

    /**
     * Charge a new amount from the next renewal on. Returns true when the provider
     * accepted the request; the change takes effect at the next renewal.
     */
    public function changeRenewalAmount(string $pspSubscriptionId, int $amountCents, string $idempotencyKey): bool;

    /**
     * The provider's view of a subscription:
     * ['status' => 'active'|'past_due'|'canceled', 'next_amount_cents' => int, 'renews_at' => string].
     * The provider renews on its own schedule and retries a declined renewal for up
     * to 7 days after the period ends. It stops only after cancelSubscription().
     */
    public function subscription(string $pspSubscriptionId): array;

    /** Stop renewals at the provider. */
    public function cancelSubscription(string $pspSubscriptionId, string $idempotencyKey): void;
}
