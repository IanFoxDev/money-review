<?php

namespace App\Services;

use App\Models\Subscription;
use Illuminate\Database\UniqueConstraintViolationException;

final class SubscriptionService
{
    /** One active subscription per user is enforced by the subscriptions_one_active index. */
    public function subscribe(int $userId, string $plan): Subscription
    {
        try {
            return Subscription::create(['user_id' => $userId, 'plan' => $plan, 'status' => 'active']);
        } catch (UniqueConstraintViolationException) {
            return Subscription::where('user_id', $userId)->where('status', 'active')->firstOrFail();
        }
    }

    /**
     * Self-serve cancel: the user keeps what they paid for until the end of the
     * period, then ExpireSubscriptions ends it and the agreement.
     */
    public function cancelAtPeriodEnd(Subscription $subscription): void
    {
        Subscription::whereKey($subscription->id)->where('status', 'active')
            ->update(['cancel_at_period_end' => true]);
    }

    /** Undo of a self-serve cancel, while the period is still running. */
    public function resume(Subscription $subscription): void
    {
        Subscription::whereKey($subscription->id)->where('status', 'active')
            ->where('current_period_end', '>', now())
            ->update(['cancel_at_period_end' => false]);
    }
}
