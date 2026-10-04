<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

final class Payment extends Model
{
    protected $fillable = ['user_id', 'amount_cents', 'refunded_cents', 'currency', 'status', 'psp_reference'];
}
