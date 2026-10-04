<?php

namespace App\Http\Controllers;

use App\Models\Account;
use App\Models\Payment;
use App\Services\Ledger;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;

/** chargeback.created events. The signature is checked by the VerifyPspSignature middleware. */
final class ChargebackWebhookController
{
    public function __construct(private Ledger $ledger)
    {
    }

    public function __invoke(Request $request): Response
    {
        $eventId = (string) $request->input('id');
        $reference = (string) $request->input('data.reference');

        DB::transaction(function () use ($eventId, $reference) {
            $first = DB::table('processed_events')->insertOrIgnore([
                'source' => 'psp', 'event_id' => $eventId, 'created_at' => now(),
            ]);
            if ($first === 0) {
                return; // a retry of an event we already handled
            }

            $payment = Payment::where('psp_reference', $reference)->lockForUpdate()->first();
            if ($payment === null || $payment->status !== 'succeeded') {
                return;
            }

            // One chargeback per payment, for the full amount, so the payment id is the key.
            $this->ledger->transfer(
                "chargeback:{$payment->id}",
                Account::system('psp_clearing', $payment->currency),
                Account::system('chargebacks', $payment->currency),
                $payment->amount_cents,
                'chargeback',
            );
            $payment->status = 'charged_back';
            $payment->save();
        });

        return response()->noContent();
    }
}
