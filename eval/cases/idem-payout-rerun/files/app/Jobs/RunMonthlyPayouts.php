<?php

namespace App\Jobs;

use App\Exceptions\GatewayDeclined;
use App\Exceptions\GatewayTimeout;
use App\Models\Account;
use App\Models\Payout;
use App\Services\Ledger;
use App\Services\PaymentGateway;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Pays every partner their balance. Runs on the 1st; finance can also trigger it by
 * hand for partners who asked for an early payout.
 */
final class RunMonthlyPayouts implements ShouldQueue
{
    public function __construct(public string $period)
    {
    }

    public function handle(Ledger $ledger, PaymentGateway $gateway): void
    {
        $accounts = Account::where('owner_type', 'partner')->where('balance_cents', '>', 0)->get();

        foreach ($accounts as $account) {
            $run = (string) Str::ulid();
            $payout = DB::transaction(function () use ($account, $ledger, $run) {
                $payout = Payout::create([
                    'partner_id' => $account->owner_id,
                    'period' => $this->period,
                    'amount_cents' => $account->balance_cents,
                    'currency' => $account->currency,
                    'status' => 'pending',
                ]);
                $ledger->transfer(
                    "payout:{$run}",
                    $account,
                    Account::system('payouts_in_flight', $account->currency),
                    $payout->amount_cents,
                    'payout',
                );

                return $payout;
            });

            try {
                $reference = $gateway->payout($payout->partner_id, $payout->amount_cents, $payout->currency, "payout-{$payout->id}");
                Payout::whereKey($payout->id)->where('status', 'pending')
                    ->update(['status' => 'sent', 'psp_reference' => $reference]);
            } catch (GatewayTimeout) {
                // Unknown outcome: stays pending, ResolvePendingPayouts asks the provider.
            } catch (GatewayDeclined) {
                DB::transaction(function () use ($payout, $ledger, $account) {
                    $moved = Payout::whereKey($payout->id)->where('status', 'pending')->update(['status' => 'failed']);
                    if ($moved === 1) {
                        $ledger->transfer(
                            "payout-return:{$payout->id}",
                            Account::system('payouts_in_flight', $account->currency),
                            $account,
                            $payout->amount_cents,
                            'payout_return',
                        );
                    }
                });
            }
        }
    }
}
