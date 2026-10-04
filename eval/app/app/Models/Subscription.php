<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

final class Subscription extends Model
{
    protected $fillable = ['user_id', 'plan', 'status'];
}
