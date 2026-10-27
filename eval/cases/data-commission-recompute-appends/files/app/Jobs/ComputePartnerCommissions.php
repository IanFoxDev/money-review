<?php

namespace App\Jobs;

use App\Models\Account;
use App\Models\Payment;
use App\Services\Ledger;
use Carbon\CarbonImmutable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\DB;

/**
 * Monthly partner commission: 7% of the payments of the users a partner referred.
 * Builds the partner's statement lines for the period and credits each line to the
 * partner account. Dispatched on the 1st for the month before; finance runs it again
 * for a month when payments were corrected after the 1st (a late provider import, a
 * wrong partner on a user).
 */
final class ComputePartnerCommissions implements ShouldQueue
{
    private const PERCENT = 7;

    public function __construct(public string $period) // Y-m
    {
    }

    public function handle(Ledger $ledger): void
    {
        $from = CarbonImmutable::createFromFormat('!Y-m', $this->period, 'UTC');
        if ($from === false || $from->format('Y-m') !== $this->period) {
            throw new \InvalidArgumentException("Bad period {$this->period}");
        }
        $to = $from->addMonthNoOverflow();

        $totals = Payment::query()
            ->whereNotNull('partner_id')
            ->where('status', 'succeeded')
            ->where('paid_at', '>=', $from)
            ->where('paid_at', '<', $to)
            ->groupBy('partner_id', 'currency')
            ->selectRaw('partner_id, currency, SUM(amount_cents - refunded_cents) AS base_cents')
            ->orderBy('partner_id')
            ->get();

        foreach ($totals as $row) {
            $commission = intdiv((int) $row->base_cents * self::PERCENT, 100);
            if ($commission === 0) {
                continue;
            }

            DB::transaction(function () use ($ledger, $row, $commission) {
                $lineId = DB::table('partner_commission_lines')->insertGetId([
                    'period' => $this->period,
                    'partner_id' => $row->partner_id,
                    'currency' => $row->currency,
                    'base_cents' => (int) $row->base_cents,
                    'commission_cents' => $commission,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);

                // One ledger transaction per statement line.
                $ledger->transfer(
                    "commission-line:{$lineId}",
                    Account::system('revenue', $row->currency),
                    Account::firstOrCreate(['owner_type' => 'partner', 'owner_id' => $row->partner_id, 'currency' => $row->currency]),
                    $commission,
                    'partner_commission',
                );
            });
        }
    }
}
