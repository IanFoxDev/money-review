<?php

namespace App\Services;

final class RevenueShare
{
    /**
     * Splits a pool of cents by integer weights. Shares always add up to the pool:
     * the cents left after flooring go one by one to the largest remainders, ties
     * by partner id.
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
        $remainders = [];
        foreach ($weights as $partnerId => $weight) {
            $shares[$partnerId] = intdiv($poolCents * $weight, $total);
            $remainders[$partnerId] = ($poolCents * $weight) % $total;
        }

        $left = $poolCents - array_sum($shares);
        uksort($remainders, fn ($a, $b) => [$remainders[$b], $a] <=> [$remainders[$a], $b]);
        foreach (array_slice(array_keys($remainders), 0, $left) as $partnerId) {
            $shares[$partnerId]++;
        }

        return $shares;
    }
}
