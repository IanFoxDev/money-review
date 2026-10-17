<?php

namespace App\Jobs;

use App\Models\Subscription;
use App\Services\RecurringBilling;
use Illuminate\Contracts\Queue\ShouldQueue;

/** Ends subscriptions cancelled at period end once the period is over. Runs hourly. */
final class ExpireSubscriptions implements ShouldQueue
{
    public function handle(RecurringBilling $billing): void
    {
        $ending = Subscription::where('status', 'active')
            ->where('cancel_at_period_end', true)
            ->where('current_period_end', '<=', now())
            ->get();

        foreach ($ending as $subscription) {
            $moved = Subscription::whereKey($subscription->id)->where('status', 'active')
                ->update(['status' => 'canceled']);
            if ($moved === 1 && $subscription->agreement_id !== null) {
                $billing->cancelAgreement($subscription->agreement_id, "cancel:{$subscription->id}");
            }
        }
    }
}
