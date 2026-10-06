<?php

namespace App\Services;

interface PartnerNotifier
{
    /** Emails the partner that the payout is approved and will arrive in 1-2 business days. */
    public function payoutOnTheWay(int $partnerId, int $amountCents, string $currency): void;
}
