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
        $refund = DB::transaction(function () use ($paymentId, $amountCents, $reason) {
            $payment = Payment::findOrFail($paymentId);

            $existing = Refund::where('payment_id', $paymentId)->where('reason', $reason)->first();
            if ($existing !== null) {
                return $existing;
            }

            // refunded_cents drifted in the past, so the cap is computed from the refunds table.
            $alreadyRefunded = (int) Refund::where('payment_id', $paymentId)
                ->whereIn('status', ['pending', 'succeeded'])->sum('amount_cents');
            if ($payment->status !== 'succeeded' || $amountCents <= 0
                || $alreadyRefunded + $amountCents > $payment->amount_cents) {
                throw new \DomainException('Refund not allowed');
            }

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
            Refund::whereKey($refund->id)->where('status', 'pending')->update(['status' => 'failed']);

            return $refund->refresh();
        }

        Refund::whereKey($refund->id)->where('status', 'pending')
            ->update(['status' => 'succeeded', 'psp_reference' => $reference]);

        return $refund->refresh();
    }
}
