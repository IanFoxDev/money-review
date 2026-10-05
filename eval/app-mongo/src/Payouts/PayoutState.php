<?php

declare(strict_types=1);

namespace App\Payouts;

final class PayoutState
{
    public function __construct(
        public readonly bool $sent,
        public readonly bool $failed,
        public readonly ?string $reference = null,
    ) {
    }
}
