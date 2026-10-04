<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

final class Refund extends Model
{
    protected $fillable = ['payment_id', 'amount_cents', 'reason', 'status', 'psp_reference'];
}
