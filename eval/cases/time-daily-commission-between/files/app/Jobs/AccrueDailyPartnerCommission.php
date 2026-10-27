<?php

namespace App\Jobs;

use App\Models\Account;
use App\Models\Payment;
use App\Services\Ledger;
use Carbon\CarbonImmutable;
use Illuminate\Contracts\Queue\ShouldQueue;

/**
 * Credits partners 7% of the payments their users made on one day. Partner days are
 * UTC days, as in the partner agreement. Dispatched every night for the day before;
 * safe to re-run for a day, one ledger transaction per partner, currency and day.
 */
final class AccrueDailyPartnerCommission implements ShouldQueue
{
    private const PERCENT = 7;

    public function __construct(public string $day) // Y-m-d
    {
    }

    public function handle(Ledger $ledger): void
    {
        $from = CarbonImmutable::createFromFormat('!Y-m-d', $this->day, 'UTC');
        $to = $from->addDay();

        $totals = Payment::query()
            ->whereNotNull('partner_id')
            ->whereIn('status', ['succeeded', 'refunded'])
            ->whereBetween('paid_at', [$from, $to])
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
