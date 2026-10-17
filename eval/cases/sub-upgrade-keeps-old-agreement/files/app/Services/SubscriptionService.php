<?php

namespace App\Services;

use App\Models\Subscription;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;

final class SubscriptionService
{
    public function __construct(private RecurringBilling $billing)
    {
    }

    /** One active subscription per user is enforced by the subscriptions_one_active index. */
    public function subscribe(int $userId, string $plan): Subscription
    {
        try {
            return Subscription::create(['user_id' => $userId, 'plan' => $plan, 'status' => 'active']);
        } catch (UniqueConstraintViolationException) {
            return Subscription::where('user_id', $userId)->where('status', 'active')->firstOrFail();
        }
    }

    /** Ends the subscription now and stops the recurring charge at the provider. */
    public function cancel(Subscription $subscription): void
    {
        $moved = Subscription::whereKey($subscription->id)->where('status', 'active')
            ->update(['status' => 'canceled']);
        if ($moved === 1 && $subscription->agreement_id !== null) {
            $this->billing->cancelAgreement($subscription->agreement_id, "cancel:{$subscription->id}");
        }
    }

    /**
     * Moves the user to another plan from the next period. The new agreement is
     * created first: if the provider refuses the card, the user keeps the old plan.
     * The paid period carries over, the new price is charged from its end.
     */
    public function changePlan(int $userId, string $plan, int $priceCents, string $currency): Subscription
    {
        $current = Subscription::where('user_id', $userId)->where('status', 'active')->firstOrFail();
        if ($current->plan === $plan) {
            return $current;
        }

        $agreementId = $this->billing->createAgreement(
            $userId, $plan, $priceCents, $currency, "agreement:{$current->id}:{$plan}",
        );

        return DB::transaction(function () use ($current, $userId, $plan, $priceCents, $currency, $agreementId) {
            $old = Subscription::whereKey($current->id)->where('status', 'active')->lockForUpdate()->first();
            if ($old === null) {
                throw new \DomainException('The subscription changed while the plan was being switched');
            }
            $old->status = 'replaced';
            $old->save();

            return Subscription::create([
                'user_id' => $userId,
                'plan' => $plan,
                'status' => 'active',
                'price_cents' => $priceCents,
                'currency' => $currency,
                'agreement_id' => $agreementId,
                'started_at' => now(),
                'current_period_end' => $old->current_period_end,
            ]);
        });
    }
}
