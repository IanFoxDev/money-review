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
}
