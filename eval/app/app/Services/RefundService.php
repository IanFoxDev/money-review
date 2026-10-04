<?php

namespace App\Services;

use App\Exceptions\GatewayDeclined;
use App\Exceptions\GatewayTimeout;
use App\Models\Payment;
use App\Models\Refund;
use Illuminate\Support\Facades\DB;

final class RefundService
{
    public function __construct(private PaymentGateway $gateway)
    {
    }

    public function refund(int $paymentId, int $amountCents, string $reason): Refund
    {
        // Reserve the amount on the payment and record the refund before calling the provider.
        $refund = DB::transaction(function () use ($paymentId, $amountCents, $reason) {
            $payment = Payment::whereKey($paymentId)->lockForUpdate()->firstOrFail();

            $existing = Refund::where('payment_id', $paymentId)->where('reason', $reason)->first();
            if ($existing !== null) {
                return $existing;
            }
            if ($payment->status !== 'succeeded' || $amountCents <= 0
                || $payment->refunded_cents + $amountCents > $payment->amount_cents) {
                throw new \DomainException('Refund not allowed');
            }

            $payment->refunded_cents += $amountCents;
            $payment->save();

            return Refund::create([
                'payment_id' => $paymentId,
                'amount_cents' => $amountCents,
                'reason' => $reason,
                'status' => 'pending',
            ]);
        });

        if ($refund->status !== 'pending') {
            return $refund;
        }

        $payment = Payment::findOrFail($paymentId);
        try {
            $reference = $this->gateway->refund($payment->psp_reference, $refund->amount_cents, $payment->currency, "refund-{$refund->id}");
        } catch (GatewayTimeout) {
            return $refund; // unknown outcome, ResolvePendingRefunds asks the provider later
        } catch (GatewayDeclined) {
            $this->release($refund);

            return $refund->refresh();
        }

        Refund::whereKey($refund->id)->where('status', 'pending')
            ->update(['status' => 'succeeded', 'psp_reference' => $reference]);

        return $refund->refresh();
    }

    private function release(Refund $refund): void
    {
        DB::transaction(function () use ($refund) {
            $moved = Refund::whereKey($refund->id)->where('status', 'pending')->update(['status' => 'failed']);
            if ($moved === 1) {
                Payment::whereKey($refund->payment_id)->decrement('refunded_cents', $refund->amount_cents);
            }
        });
    }
}
