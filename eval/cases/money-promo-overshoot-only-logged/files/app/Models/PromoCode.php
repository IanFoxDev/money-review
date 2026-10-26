<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

final class PromoCode extends Model
{
    protected $fillable = ['code', 'discount_cents', 'activation_limit', 'activations'];

    public function isUsedUp(): bool
    {
        return $this->activation_limit !== null && $this->activations >= $this->activation_limit;
    }
}
