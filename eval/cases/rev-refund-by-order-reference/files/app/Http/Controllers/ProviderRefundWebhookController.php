<?php

namespace App\Http\Controllers;

use App\Models\Payment;
use App\Models\Refund;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * refund.succeeded events for refunds made outside our app (the provider dashboard,
 * the provider's support). Refunds we start ourselves carry our idempotency key
 * (refund-{id}) and are booked by RefundService and ResolvePendingRefunds, so they
 * are skipped here. The signature is checked by the VerifyPspSignature middleware.
 *
 * Payload: {"id": "evt_...", "type": "refund.succeeded", "data": {"refund_id": "...",
 * "merchant_reference": "...", "charge_reference": "...", "amount_cents": 500, "currency": "EUR",
 * "idempotency_key": null}}
 */
final class ProviderRefundWebhookController
{
    public function __invoke(Request $request): Response
    {
        if ($request->input('type') !== 'refund.succeeded') {
            return response()->noContent(); // other types are handled by PspWebhookController
        }

        if ($request->input('data.idempotency_key') !== null) {
            return response()->noContent(); // started by us
        }

        $eventId = (string) $request->input('id');
        $refundId = (string) $request->input('data.refund_id');
        $orderReference = (string) $request->input('data.merchant_reference');
        $amountCents = (int) $request->input('data.amount_cents');
        $currency = (string) $request->input('data.currency');

        DB::transaction(function () use ($eventId, $refundId, $orderReference, $amountCents, $currency) {
            $first = DB::table('processed_events')->insertOrIgnore([
                'source' => 'psp', 'event_id' => $eventId, 'created_at' => now(),
            ]);
            if ($first === 0) {
                return;
            }

            $payment = Payment::where('order_reference', $orderReference)
                ->where('status', 'succeeded')
                ->lockForUpdate()
                ->first();
            if ($payment === null) {
                throw new \UnexpectedValueException("refund {$refundId}: no settled payment for order {$orderReference}");
            }
            if ($currency !== $payment->currency || $amountCents <= 0
                || $payment->refunded_cents + $amountCents > $payment->amount_cents) {
                Log::warning('provider refund does not fit the payment', [
                    'refund_id' => $refundId, 'payment_id' => $payment->id, 'amount_cents' => $amountCents,
                ]);
                throw new \UnexpectedValueException("refund {$refundId} does not fit payment {$payment->id}");
            }

            Refund::create([
                'payment_id' => $payment->id,
                'amount_cents' => $amountCents,
                'reason' => "provider:{$refundId}",
                'status' => 'succeeded',
                'psp_reference' => $refundId,
            ]);
            $payment->refunded_cents += $amountCents;
            $payment->save();
        });

        return response()->noContent();
    }
}
