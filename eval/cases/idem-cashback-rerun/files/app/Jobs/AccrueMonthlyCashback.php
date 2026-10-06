<?php

namespace App\Jobs;

use App\Models\Account;
use App\Services\Ledger;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\DB;

/**
 * Pays 1% cashback on last month's successful payments, net of refunds. Scheduled on
 * the 2nd at 03:00; if it fails, the on-call engineer runs it again for the same
 * period. cashback_expense is an expense account and may go negative.
 */
final class AccrueMonthlyCashback implements ShouldQueue
{
    private const RATE_BPS = 100;

    public function __construct(public string $period)
    {
    }

    public function handle(Ledger $ledger): void
    {
        $rows = DB::table('payments')
            ->where('status', 'succeeded')
            ->where('created_at', 'like', $this->period.'%')
            ->groupBy('user_id', 'currency')
            ->selectRaw('user_id, currency, sum(amount_cents - refunded_cents) as net_cents')
            ->get();

        foreach ($rows as $row) {
            $cashback = intdiv((int) $row->net_cents * self::RATE_BPS, 10000);
            if ($cashback <= 0) {
                continue;
            }

            $ledger->transfer(
                "cashback:{$row->user_id}:{$row->currency}:".now()->format('Y-m-d'),
                Account::system('cashback_expense', $row->currency),
                Account::forUser((int) $row->user_id, $row->currency),
                $cashback,
                'cashback',
            );
        }
    }
}
