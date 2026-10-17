<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            $table->unsignedBigInteger('partner_id')->nullable(); // the partner who referred the user
            $table->timestamp('paid_at')->nullable();              // when the payment succeeded, UTC
            $table->index(['paid_at', 'partner_id']);
        });
    }
};
