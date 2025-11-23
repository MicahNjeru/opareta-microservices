import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsEnum, IsOptional, IsString } from 'class-validator';
import { PaymentStatus } from '../entities/payment.entity';

export class UpdateStatusDto {
  @ApiProperty({
    example: 'PENDING',
    enum: PaymentStatus,
    description: 'New payment status',
  })
  @IsNotEmpty()
  @IsEnum(PaymentStatus)
  status: PaymentStatus;

  @ApiProperty({
    example: 'TXN123456789',
    description: 'Provider transaction ID',
    required: false,
  })
  @IsOptional()
  @IsString()
  provider_transaction_id?: string;
}