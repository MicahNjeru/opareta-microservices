import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { HttpModule } from '@nestjs/axios';
import { PaymentsController } from './payments.controller';
import { PaymentsService } from './payments.service';
import { StateMachineService } from './services/state-machine.service';
import { Payment } from './entities/payment.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([Payment]),
    HttpModule,
  ],
  controllers: [PaymentsController],
  providers: [PaymentsService, StateMachineService],
  exports: [PaymentsService],
})
export class PaymentsModule {}