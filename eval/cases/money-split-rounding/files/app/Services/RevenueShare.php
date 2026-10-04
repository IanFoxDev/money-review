<?php

namespace App\Services;

final class RevenueShare
{
    /**
     * Splits a pool of cents by integer weights.
     *
     * @param array<int, int> $weights partner id => weight
     * @return array<int, int> partner id => cents
     */
    public function split(int $poolCents, array $weights): array
    {
        $total = array_sum($weights);
        if ($poolCents < 0 || $total <= 0) {
            throw new \InvalidArgumentException('Nothing to split');
        }

        $shares = [];
        foreach ($weights as $partnerId => $weight) {
            $shares[$partnerId] = (int) round($poolCents * $weight / $total);
        }

        return $shares;
    }
}
