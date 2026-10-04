<?php

namespace App\Services;

interface PayoutNotifier
{
    /** Publishes to the message broker. Partners' accounting systems consume it. */
    public function payoutSent(int $payoutId, int $partnerId, int $amountCents, string $currency): void;
}
