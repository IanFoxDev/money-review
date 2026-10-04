<?php

namespace App\Jobs;

use App\Models\Payout;
use App\Services\PayoutNotifier;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\DB;

/** Called when the provider confirms a payout. */
final class MarkPayoutSent implements ShouldQueue
{
    public function __construct(public int $payoutId, public string $reference)
    {
    }

    public function handle(PayoutNotifier $notifier): void
    {
        $payout = DB::transaction(function () {
            $moved = Payout::whereKey($this->payoutId)->where('status', 'pending')
                ->update(['status' => 'sent', 'psp_reference' => $this->reference]);

            return $moved === 1 ? Payout::findOrFail($this->payoutId) : null;
        });

        if ($payout !== null) {
            $notifier->payoutSent($payout->id, $payout->partner_id, $payout->amount_cents, $payout->currency);
        }
    }
}
