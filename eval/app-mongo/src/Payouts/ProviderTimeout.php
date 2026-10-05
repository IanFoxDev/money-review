<?php

declare(strict_types=1);

namespace App\Payouts;

/** The provider did not answer in time. The payout may or may not have been sent. */
final class ProviderTimeout extends \RuntimeException
{
}
