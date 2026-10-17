<?php

declare(strict_types=1);

namespace App\Payments;

use MongoDB\Client;
use MongoDB\Collection;

/**
 * Server-to-server result callback of Paywise, a hosted card page. The body is
 * form-encoded:
 *
 *   payment_id=...&txn_id=...&approved=true&reason=&signature=...
 *
 * The signature is an HMAC-SHA256 of the body without the signature field. Paywise
 * retries until it gets a 200, so a repeated callback must change nothing.
 */
final class PaywiseCallback
{
    private Collection $payments;

    public function __construct(
        Client $client,
        private PaymentService $paymentService,
        private string $secret,
        string $db = 'billing',
    ) {
        $this->payments = $client->selectCollection($db, 'payments');
    }

    /** Returns the HTTP status to answer with. */
    public function handle(string $rawBody): int
    {
        parse_str($rawBody, $fields);

        $signature = (string) ($fields['signature'] ?? '');
        $signed = preg_replace('/(^|&)signature=[^&]*/', '', $rawBody);
        if (! hash_equals(hash_hmac('sha256', (string) $signed, $this->secret), $signature)) {
            return 401;
        }

        $paymentId = (string) ($fields['payment_id'] ?? '');
        $txnId = (string) ($fields['txn_id'] ?? '');
        if ($paymentId === '' || $txnId === '') {
            return 400;
        }

        $approved = (bool) ($fields['approved'] ?? false);

        if ($approved) {
            // Dedup by the Paywise transaction id, the state guard and the ledger key are in confirm().
            $this->paymentService->confirm('paywise:' . $txnId, $paymentId);

            return 200;
        }

        $this->payments->updateOne(
            ['_id' => $paymentId, 'status' => 'pending'],
            ['$set' => [
                'status' => 'failed',
                'failure_reason' => (string) ($fields['reason'] ?? ''),
                'failed_at' => new \MongoDB\BSON\UTCDateTime(),
            ]],
        );

        return 200;
    }
}
