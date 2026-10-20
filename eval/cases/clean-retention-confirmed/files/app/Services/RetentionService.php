<?php

namespace App\Services;

use App\Exceptions\RetentionNotAvailable;
use App\Models\Subscription;
use Illuminate\Support\Facades\Log;

final class RetentionService
{
    public function __construct(private PaymentGateway $gateway)
    {
    }

    /**
     * The user accepted the offer on the cancel page: half price from the next renewal.
     * The discount counts as applied only when the provider shows the new amount.
     */
    public function acceptHalfPrice(Subscription $subscription): void
    {
        // The offer is accepted once: a double click or a second tab claims nothing.
        $claimed = Subscription::whereKey($subscription->id)
            ->whereNull('discount_status')
            ->update(['discount_status' => 'requested']);
        if ($claimed === 0) {
            return;
        }

        $discounted = intdiv($subscription->price_cents, 2); // plans are priced in even cents

        $accepted = $this->gateway->changeRenewalAmount(
            $subscription->psp_subscription_id,
            $discounted,
            "retention:{$subscription->id}",
        );
        if (! $accepted) {
            $subscription->update(['discount_status' => null]);
            throw new RetentionNotAvailable();
        }

        $remote = $this->gateway->subscription($subscription->psp_subscription_id);
        if ((int) $remote['next_amount_cents'] !== $discounted) {
            $subscription->update(['discount_status' => 'not_applied']);
            Log::warning('retention discount not applied by the provider', ['subscription' => $subscription->id]);
            throw new RetentionNotAvailable();
        }

        $subscription->update(['discount_status' => 'applied', 'price_cents' => $discounted]);
    }
}
