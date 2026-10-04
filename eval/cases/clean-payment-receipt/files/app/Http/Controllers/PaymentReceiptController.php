<?php

namespace App\Http\Controllers;

use App\Models\Payment;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** Read-only receipt for the user's own payment. */
final class PaymentReceiptController
{
    private const SCALE = ['JPY' => 0, 'KWD' => 3];

    public function show(Request $request, int $paymentId): JsonResponse
    {
        $payment = Payment::where('user_id', $request->user()->id)->findOrFail($paymentId);
        $scale = self::SCALE[$payment->currency] ?? 2;

        return response()->json([
            'id' => $payment->id,
            'status' => $payment->status,
            'currency' => $payment->currency,
            'amount_cents' => $payment->amount_cents,
            'refunded_cents' => $payment->refunded_cents,
            // Display only, never parsed back.
            'amount_display' => number_format($payment->amount_cents / (10 ** $scale), $scale).' '.$payment->currency,
        ]);
    }
}
