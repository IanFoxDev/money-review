<?php

declare(strict_types=1);

namespace App\Payments;

use App\Money\Ledger;
use MongoDB\BSON\UTCDateTime;
use MongoDB\Client;
use MongoDB\Collection;
use MongoDB\Driver\Session;

use function MongoDB\with_transaction;

/**
 * Settles payments whose payment.succeeded webhook never arrived. The provider's daily
 * report lists every successful charge; a nightly job passes each row here, and the
 * payments that are still pending on our side are completed like a webhook would.
 */
final class MissedPaymentRecovery
{
    private Collection $payments;

    public function __construct(private Client $client, private Ledger $ledger, string $db = 'billing')
    {
        $this->payments = $client->selectCollection($db, 'payments');
    }

    /**
     * @param array{payment_id: string, amount: int, currency: string, charge_id: string} $row
     * @return bool true when the payment was completed by this call
     */
    public function recover(array $row): bool
    {
        $recovered = false;
        $session = $this->client->startSession();

        with_transaction($session, function (Session $session) use ($row, &$recovered): void {
            $recovered = false;

            $payment = $this->payments->findOne(['_id' => $row['payment_id']], ['session' => $session]);
            if ($payment === null || $payment['status'] !== 'pending') {
                return; // unknown here, or the webhook got there first
            }
            if ((int) $payment['amount'] !== $row['amount'] || $payment['currency'] !== $row['currency']) {
                throw new \UnexpectedValueException("Report row for {$row['payment_id']} does not match the payment");
            }

            $updated = $this->payments->updateOne(
                ['_id' => $row['payment_id'], 'status' => 'pending'],
                ['$set' => [
                    'status' => 'paid',
                    'paid_at' => new UTCDateTime(),
                    'charge_id' => $row['charge_id'],
                    'recovered_from_report' => true,
                ]],
                ['session' => $session],
            );
            if ($updated->getModifiedCount() === 0) {
                return;
            }

            // Same ledger key as PaymentService::confirm(): a webhook that arrives late is a no-op.
            $this->ledger->applyInSession(
                $session,
                'payment:' . $row['payment_id'],
                'clearing:' . $payment['currency'],
                'user:' . $payment['user_id'] . ':' . $payment['currency'],
                (int) $payment['amount'],
                $payment['currency'],
            );
            $recovered = true;
        });

        return $recovered;
    }
}
