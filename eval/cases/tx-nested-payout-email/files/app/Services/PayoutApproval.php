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
        $approved = DB::transaction(function () use ($payout) {
            $moved = Payout::whereKey($payout->id)->where('status', 'requested')->update(['status' => 'approved']);
            if ($moved === 0) {
                return false;
            }
            $this->ledger->transfer(
                "payout:{$payout->id}",
                Account::where('owner_type', 'partner')->where('owner_id', $payout->partner_id)
                    ->where('currency', $payout->currency)->firstOrFail(),
                Account::system('payouts_in_flight', $payout->currency),
                $payout->amount_cents,
                'payout',
            );

            return true;
        });

        // After the commit, so a partner is never told about a payout we did not record.
        if ($approved) {
            $this->notifier->payoutOnTheWay($payout->partner_id, $payout->amount_cents, $payout->currency);
        }
    }
}
