<?php

namespace App\Jobs;

use App\Models\Subscription;

/** Nightly. A subscription whose paid period is over loses access, and the user can subscribe again. */
final class ExpireSubscriptions
{
    public function handle(): void
    {
        Subscription::where('status', 'active')
            ->where('expires_at', '<', now())
            ->update(['status' => 'expired']);
    }
}
