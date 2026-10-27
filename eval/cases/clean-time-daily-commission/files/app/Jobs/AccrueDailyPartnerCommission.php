<?php

namespace App\Jobs;

use App\Models\Account;
use App\Models\Payment;
use App\Services\Ledger;
use Carbon\CarbonImmutable;
use Illuminate\Contracts\Queue\ShouldQueue;

/**
 * Credits partners 7% of the payments their users made on one day. A partner day is
 * a calendar day in Europe/Nicosia, as in the partner agreement; paid_at is stored in
 * UTC. Dispatched every night for the day before; safe to re-run for a day, one
 * ledger transaction per partner, currency and day.
 */
final class AccrueDailyPartnerCommission implements ShouldQueue
{
    private const PERCENT = 7;
    private const ZONE = 'Europe/Nicosia';

    public function __construct(public string $day) // Y-m-d
    {
    }

    public function handle(Ledger $ledger): void
    {
        $day = CarbonImmutable::createFromFormat('!Y-m-d', $this->day, self::ZONE);
        if ($day === false || $day->format('Y-m-d') !== $this->day) {
            throw new \InvalidArgumentException("Bad day {$this->day}");
        }
        // [from, to): the next local midnight, then both in UTC. A DST day is 23 or 25 hours.
        $from = $day->utc();
        $to = $day->addDay()->utc();

        $totals = Payment::query()
            ->whereNotNull('partner_id')
            ->whereIn('status', ['succeeded', 'refunded'])
            ->where('paid_at', '>=', $from)
            ->where('paid_at', '<', $to)
            ->groupBy('partner_id', 'currency')
            ->selectRaw('partner_id, currency, SUM(amount_cents) AS total_cents')
            ->get();

        foreach ($totals as $row) {
            // Rounded down to the cent, as the partner agreement says.
            $commission = intdiv((int) $row->total_cents * self::PERCENT, 100);
            if ($commission === 0) {
                continue;
            }

            $ledger->transfer(
                "partner-commission:{$row->partner_id}:{$row->currency}:{$this->day}",
                Account::system('revenue', $row->currency),
                Account::firstOrCreate(['owner_type' => 'partner', 'owner_id' => $row->partner_id, 'currency' => $row->currency]),
                $commission,
                'partner_commission',
            );
        }
    }
}
