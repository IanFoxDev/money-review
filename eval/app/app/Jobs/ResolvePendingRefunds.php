<?php

namespace App\Jobs;

use App\Models\Payment;
use App\Models\Refund;
use App\Services\PaymentGateway;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\DB;

/** Settles refunds whose provider call timed out, by asking the provider. */
final class ResolvePendingRefunds implements ShouldQueue
{
    public function handle(PaymentGateway $gateway): void
    {
        $pending = Refund::where('status', 'pending')->where('created_at', '<', now()->subMinutes(10))->get();

        foreach ($pending as $refund) {
            $state = $gateway->status("refund-{$refund->id}");
            if ($state === 'succeeded') {
                Refund::whereKey($refund->id)->where('status', 'pending')->update(['status' => 'succeeded']);
            } elseif ($state === 'failed') {
                DB::transaction(function () use ($refund) {
                    $moved = Refund::whereKey($refund->id)->where('status', 'pending')->update(['status' => 'failed']);
                    if ($moved === 1) {
                        Payment::whereKey($refund->payment_id)->decrement('refunded_cents', $refund->amount_cents);
                    }
                });
            }
        }
    }
}
