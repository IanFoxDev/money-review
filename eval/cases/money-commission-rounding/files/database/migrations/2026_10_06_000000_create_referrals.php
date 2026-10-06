<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('referrals', function (Blueprint $table) {
            $table->foreignId('user_id')->primary();  // a user is referred by one partner
            $table->foreignId('partner_id')->index();
            $table->timestamp('created_at');
        });
    }
};
