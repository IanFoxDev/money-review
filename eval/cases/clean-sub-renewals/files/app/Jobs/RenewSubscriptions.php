<?php

namespace App\Jobs;

use App\Exceptions\GatewayDeclined;
use App\Exceptions\GatewayTimeout;
use App\Models\Subscription;
use App\Services\BillingPeriod;
use App\Services\RecurringBilling;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\DB;

/**
 * Charges subscriptions whose period has ended, every ten minutes. One charge row per
 * subscription and period, created before the provider call; its id is the
 * idempotency key, so a re-run or a timeout never charges a period twice.
 */
final class RenewSubscriptions implements ShouldQueue
{
    public function handle(RecurringBilling $billing): void
    {
        // Cancelled at period end: not renewed, ExpireSubscriptions ends them.
        $due = Subscription::where('status', 'active')
            ->where('cancel_at_period_end', false)
            ->whereNotNull('agreement_id')
            ->where('current_period_end', '<=', now())
            ->orderBy('id')
            ->get();

        foreach ($due as $subscription) {
            $this->renew($billing, $subscription);
        }
    }

    private function renew(RecurringBilling $billing, Subscription $subscription): void
    {
        $periodEnd = $subscription->current_period_end;

        DB::table('subscription_charges')->insertOrIgnore([
            'subscription_id' => $subscription->id,
            'period_end' => $periodEnd,
            'amount_cents' => $subscription->price_cents,
            'currency' => $subscription->currency,
            'status' => 'pending',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $charge = DB::table('subscription_charges')
            ->where('subscription_id', $subscription->id)->where('period_end', $periodEnd)->first();
        if ($charge->status !== 'pending') {
            return;
        }

        try {
            $reference = $billing->charge($subscription->agreement_id, $charge->amount_cents, $charge->currency, "renewal:{$charge->id}");
        } catch (GatewayTimeout) {
            return; // unknown outcome: the next run calls again with the same key
        } catch (GatewayDeclined) {
            DB::transaction(function () use ($charge, $subscription) {
                $moved = DB::table('subscription_charges')->where('id', $charge->id)->where('status', 'pending')
                    ->update(['status' => 'failed', 'updated_at' => now()]);
                if ($moved === 1) {
                    Subscription::whereKey($subscription->id)->where('status', 'active')->update(['status' => 'past_due']);
                }
            });

            return;
        }

        DB::transaction(function () use ($charge, $subscription, $periodEnd, $reference) {
            $moved = DB::table('subscription_charges')->where('id', $charge->id)->where('status', 'pending')
                ->update(['status' => 'succeeded', 'psp_reference' => $reference, 'updated_at' => now()]);
            if ($moved === 1) {
                Subscription::whereKey($subscription->id)->where('current_period_end', $periodEnd)
                    ->update(['current_period_end' => BillingPeriod::next($subscription->started_at, $periodEnd)]);
            }
        });
    }
}
