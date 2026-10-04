<?php

namespace App\Services;

/** Platform fee charged to partners on each payout. */
final class FeeCalculator
{
    public function __construct(private float $percent = 2.9, private int $fixedCents = 30)
    {
    }

    /** @return array{fee: int, net: int} */
    public function forPayout(int $amountCents): array
    {
        $amount = $amountCents / 100;
        $fee = round($amount * $this->percent / 100, 2) + $this->fixedCents / 100;
        $net = $amount - $fee;

        return ['fee' => (int) ($fee * 100), 'net' => (int) ($net * 100)];
    }
}
