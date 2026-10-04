<?php

namespace App\Services;

/** Splits an annual plan price into monthly charges that add up to the price. */
final class InstallmentPlan
{
    /** @return list<int> cents per month, the first months carry the leftover cents */
    public function monthly(int $priceCents, int $months): array
    {
        if ($priceCents < 0 || $months < 1) {
            throw new \InvalidArgumentException('Bad plan');
        }

        $base = intdiv($priceCents, $months);
        $left = $priceCents % $months;

        $charges = [];
        for ($i = 0; $i < $months; $i++) {
            $charges[] = $base + ($i < $left ? 1 : 0);
        }

        return $charges;
    }
}
