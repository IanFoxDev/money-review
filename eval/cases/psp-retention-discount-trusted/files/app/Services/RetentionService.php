<?php

namespace App\Services;

use App\Exceptions\RetentionNotAvailable;
use App\Models\Subscription;

final class RetentionService
{
    public function __construct(private PaymentGateway $gateway)
    {
    }

    /** The user accepted the offer on the cancel page: half price from the next renewal. */
    public function acceptHalfPrice(Subscription $subscription): void
    {
        // The offer is accepted once: a double click or a second tab claims nothing.
        $claimed = Subscription::whereKey($subscription->id)
            ->whereNull('discount_status')
            ->update(['discount_status' => 'requested']);
        if ($claimed === 0) {
            return;
        }

        $discounted = intdiv($subscription->price_cents, 2);

        $accepted = $this->gateway->changeRenewalAmount(
            $subscription->psp_subscription_id,
            $discounted,
            "retention:{$subscription->id}",
        );
        if (! $accepted) {
            $subscription->update(['discount_status' => null]);
            throw new RetentionNotAvailable();
        }

        $subscription->update(['discount_status' => 'applied', 'price_cents' => $discounted]);
    }
}
