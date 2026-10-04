<?php

namespace App\Jobs;

use App\Models\Account;
use App\Models\Payout;
use App\Services\Ledger;
use App\Services\PaymentGateway;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\DB;

/**
 * Pays every partner their balance for a period. All or nothing: if one payout
 * fails, the whole batch is rolled back and the job is retried.
 */
final class RunMonthlyPayouts implements ShouldQueue
{
    public int $tries = 3;

    public function __construct(public string $period)
    {
    }

    public function handle(Ledger $ledger, PaymentGateway $gateway): void
    {
        DB::transaction(function () use ($ledger, $gateway) {
            $accounts = Account::where('owner_type', 'partner')->where('balance_cents', '>', 0)->lockForUpdate()->get();

            foreach ($accounts as $account) {
                $payout = Payout::firstOrCreate(
                    ['partner_id' => $account->owner_id, 'period' => $this->period],
                    ['amount_cents' => $account->balance_cents, 'currency' => $account->currency, 'status' => 'pending'],
                );
                $ledger->transfer(
                    "payout:{$payout->id}",
                    $account,
                    Account::system('payouts_in_flight', $account->currency),
                    $payout->amount_cents,
                    'payout',
                );

                $reference = $gateway->payout($payout->partner_id, $payout->amount_cents, $payout->currency, "payout-{$payout->id}");
                $payout->update(['status' => 'sent', 'psp_reference' => $reference]);
            }
        });
    }
}
