<?php

declare(strict_types=1);

namespace App\Payouts;

/** Fictional payout provider. A repeated idempotency key returns the first result. */
interface PayoutProvider
{
    /** @throws ProviderTimeout|ProviderDeclined */
    public function send(string $partnerId, int $amount, string $currency, string $idempotencyKey): string;

    /** What happened to the payout sent with this key. */
    public function status(string $idempotencyKey): PayoutState;
}
