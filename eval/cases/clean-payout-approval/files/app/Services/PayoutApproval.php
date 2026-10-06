<?php

namespace App\Services;

use App\Models\Account;
use App\Models\Payout;
use Illuminate\Support\Facades\DB;

final class PayoutApproval
{
    public function __construct(private Ledger $ledger, private PartnerNotifier $notifier)
    {
    }

    /** Moves the requested amount out of the partner's balance and tells the partner. */
    public function approve(Payout $payout): void
    {
        DB::transaction(function () use ($payout) {
            $moved = Payout::whereKey($payout->id)->where('status', 'requested')->update(['status' => 'approved']);
            if ($moved === 0) {
                return;
            }
            $this->ledger->transfer(
                "payout:{$payout->id}",
                Account::where('owner_type', 'partner')->where('owner_id', $payout->partner_id)
                    ->where('currency', $payout->currency)->firstOrFail(),
                Account::system('payouts_in_flight', $payout->currency),
                $payout->amount_cents,
                'payout',
            );

            // Runs after the outermost commit: when approve() is called inside a
            // caller's transaction that rolls back, the partner is not told.
            DB::afterCommit(fn () => $this->notifier->payoutOnTheWay($payout->partner_id, $payout->amount_cents, $payout->currency));
        });
    }
}
