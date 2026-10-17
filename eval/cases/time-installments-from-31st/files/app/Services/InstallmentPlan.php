<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;

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

    /**
     * The charge dates: the first one on the day of purchase, then the same day of
     * every following month, as shown to the customer at checkout.
     *
     * @return list<array{number: int, due_on: string, amount_cents: int}>
     */
    public function schedule(int $priceCents, int $months, \DateTimeImmutable $firstDue): array
    {
        $rows = [];
        foreach ($this->monthly($priceCents, $months) as $i => $amountCents) {
            $rows[] = [
                'number' => $i + 1,
                'due_on' => $firstDue->modify("+{$i} month")->format('Y-m-d'),
                'amount_cents' => $amountCents,
            ];
        }

        return $rows;
    }

    /** Stores the schedule of a new installment subscription. Safe to call again. */
    public function store(int $subscriptionId, int $priceCents, string $currency, int $months, \DateTimeImmutable $firstDue): void
    {
        $now = now();
        $rows = array_map(fn (array $row) => $row + [
            'subscription_id' => $subscriptionId,
            'currency' => $currency,
            'status' => 'scheduled',
            'created_at' => $now,
            'updated_at' => $now,
        ], $this->schedule($priceCents, $months, $firstDue));

        DB::table('installments')->insertOrIgnore($rows);
    }
}
