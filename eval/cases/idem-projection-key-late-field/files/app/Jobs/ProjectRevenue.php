<?php

namespace App\Jobs;

use App\Models\Payment;
use Illuminate\Support\Facades\DB;

/**
 * Keeps revenue_rows in step with payments. Runs on payment.succeeded and again on
 * subscription.linked, when the subscription a payment paid for becomes known; it is
 * safe to run any number of times for the same payment.
 */
final class ProjectRevenue
{
    public function __construct(private int $paymentId, private ?int $subscriptionId = null)
    {
    }

    public function handle(): void
    {
        $payment = Payment::findOrFail($this->paymentId);
        if ($payment->status !== 'succeeded') {
            return;
        }

        DB::table('revenue_rows')->upsert(
            [[
                'payment_id' => $payment->id,
                'subscription_id' => $this->subscriptionId ?? 0,
                'amount_cents' => $payment->amount_cents - $payment->refunded_cents,
                'currency' => $payment->currency,
                'created_at' => now(),
                'updated_at' => now(),
            ]],
            ['payment_id', 'subscription_id'],
            ['amount_cents', 'updated_at'],
        );
    }
}
