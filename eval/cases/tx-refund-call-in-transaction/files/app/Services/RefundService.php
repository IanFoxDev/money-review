<?php

namespace App\Services;

use App\Models\Payment;
use App\Models\Refund;
use Illuminate\Support\Facades\DB;

final class RefundService
{
    public function __construct(private PaymentGateway $gateway)
    {
    }

    /** Simplified: one transaction, so a failed provider call leaves nothing behind. */
    public function refund(int $paymentId, int $amountCents, string $reason): Refund
    {
        return DB::transaction(function () use ($paymentId, $amountCents, $reason) {
            $payment = Payment::whereKey($paymentId)->lockForUpdate()->firstOrFail();

            $existing = Refund::where('payment_id', $paymentId)->where('reason', $reason)->first();
            if ($existing !== null) {
                return $existing;
            }
            if ($payment->status !== 'succeeded' || $amountCents <= 0
                || $payment->refunded_cents + $amountCents > $payment->amount_cents) {
                throw new \DomainException('Refund not allowed');
            }

            $refund = Refund::create([
                'payment_id' => $paymentId,
                'amount_cents' => $amountCents,
                'reason' => $reason,
                'status' => 'pending',
            ]);

            $reference = $this->gateway->refund($payment->psp_reference, $amountCents, $payment->currency, "refund-{$refund->id}");

            $payment->refunded_cents += $amountCents;
            $payment->save();
            $refund->update(['status' => 'succeeded', 'psp_reference' => $reference]);

            return $refund;
        });
    }
}
