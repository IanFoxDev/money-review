<?php

namespace App\Jobs;

use App\Exceptions\PayoutBatchLimitExceeded;
use App\Models\Payout;
use App\Services\PayoutApproval;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\DB;

/**
 * Approves the early payout requests waiting right now as one batch: either all of them
 * or none, so finance never sees a half-approved batch. The limit caps one batch; it is
 * not a daily limit. SendApprovedPayouts then pays the approved ones through the
 * provider.
 */
final class ApproveEarlyPayouts implements ShouldQueue
{
    private const BATCH_LIMIT_CENTS = 5_000_000;

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
                if ($total > self::BATCH_LIMIT_CENTS) {
                    throw new PayoutBatchLimitExceeded("Early payouts over the batch limit in {$this->currency}");
                }
            }
        });
    }
}
