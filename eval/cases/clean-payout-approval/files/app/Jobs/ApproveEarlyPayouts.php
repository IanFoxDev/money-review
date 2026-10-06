<?php

namespace App\Jobs;

use App\Exceptions\DailyPayoutLimitExceeded;
use App\Models\Payout;
use App\Services\PayoutApproval;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\DB;

/**
 * Approves the early payout requests of the day as one batch: either all of them or
 * none, so finance never sees a half-approved day. SendApprovedPayouts then pays the
 * approved ones through the provider.
 */
final class ApproveEarlyPayouts implements ShouldQueue
{
    private const DAILY_LIMIT_CENTS = 5_000_000;

    public function __construct(public string $currency)
    {
    }

    public function handle(PayoutApproval $approval): void
    {
        DB::transaction(function () use ($approval) {
            $requests = Payout::where('status', 'requested')->where('currency', $this->currency)
                ->orderBy('id')->lockForUpdate()->get();

            $total = 0;
            foreach ($requests as $payout) {
                $approval->approve($payout);

                $total += $payout->amount_cents;
                if ($total > self::DAILY_LIMIT_CENTS) {
                    throw new DailyPayoutLimitExceeded("Early payouts over the daily limit in {$this->currency}");
                }
            }
        });
    }
}
