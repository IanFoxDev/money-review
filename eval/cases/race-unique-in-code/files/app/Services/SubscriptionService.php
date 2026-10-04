<?php

namespace App\Services;

use App\Models\Subscription;

final class SubscriptionService
{
    public function subscribe(int $userId, string $plan): Subscription
    {
        $active = Subscription::where('user_id', $userId)->where('status', 'active')->first();
        if ($active !== null) {
            return $active;
        }

        return Subscription::create(['user_id' => $userId, 'plan' => $plan, 'status' => 'active']);
    }
}
