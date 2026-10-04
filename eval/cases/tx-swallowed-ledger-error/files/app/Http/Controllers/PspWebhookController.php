<?php

namespace App\Http\Controllers;

use App\Models\Account;
use App\Models\Payment;
use App\Services\Ledger;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/** Provider events. The signature is checked by the VerifyPspSignature middleware. */
final class PspWebhookController
{
    public function __construct(private Ledger $ledger)
    {
    }

    public function __invoke(Request $request): Response
    {
        $eventId = (string) $request->input('id');
        $type = (string) $request->input('type');
        $reference = (string) $request->input('data.reference');

        DB::transaction(function () use ($eventId, $type, $reference) {
            $first = DB::table('processed_events')->insertOrIgnore([
                'source' => 'psp', 'event_id' => $eventId, 'created_at' => now(),
            ]);
            if ($first === 0) {
                return; // a retry of an event we already handled
            }

            $payment = Payment::where('psp_reference', $reference)->lockForUpdate()->first();
            if ($payment === null) {
                return;
            }

            match ($type) {
                'payment.succeeded' => $this->succeeded($payment),
                'payment.failed' => $this->failed($payment),
                default => null,
            };
        });

        return response()->noContent();
    }

    private function succeeded(Payment $payment): void
    {
        if ($payment->status !== 'pending') {
            return; // late or out of order event, the state already moved
        }
        $payment->status = 'succeeded';
        $payment->save();

        try {
            $this->ledger->transfer(
                "payment:{$payment->id}",
                Account::system('psp_clearing', $payment->currency),
                Account::forUser($payment->user_id, $payment->currency),
                $payment->amount_cents,
                'top_up',
            );
        } catch (\Throwable $e) {
            // Do not make the provider retry for a ledger hiccup: it would be a duplicate event anyway.
            Log::error('Top-up ledger transfer failed', ['payment' => $payment->id, 'error' => $e->getMessage()]);
        }
    }

    private function failed(Payment $payment): void
    {
        if ($payment->status !== 'pending') {
            return;
        }
        $payment->status = 'failed';
        $payment->save();
    }
}
