import * as React from 'react'
import { Slot } from '@radix-ui/react-slot'
import { cva, type VariantProps } from 'class-variance-authority'
import { cn } from '@/lib/utils'

const buttonVariants = cva('inline-flex cursor-pointer items-center justify-center gap-2 whitespace-nowrap rounded-lg text-sm font-semibold transition-colors outline-none disabled:cursor-not-allowed disabled:opacity-45 focus-visible:ring-2 focus-visible:ring-blue-500/35', { variants: { variant: { default: 'bg-blue-600 text-white shadow-xs hover:bg-blue-700', outline: 'border border-slate-300 bg-white text-slate-800 shadow-xs hover:bg-slate-50', success: 'border border-emerald-500 bg-white text-emerald-700 hover:bg-emerald-50', danger: 'border border-red-500 bg-white text-red-600 hover:bg-red-50', warning: 'border border-amber-500 bg-white text-amber-600 hover:bg-amber-50', ghost: 'text-blue-600 hover:bg-blue-50' }, size: { default: 'h-10 px-4', sm: 'h-8 px-3 text-xs', lg: 'h-12 px-6 text-base', icon: 'size-9' } }, defaultVariants: { variant: 'default', size: 'default' } })

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement>, VariantProps<typeof buttonVariants> { asChild?: boolean }
export function Button({ className, variant, size, asChild, type, ...props }: ButtonProps) { const Comp = asChild ? Slot : 'button'; return <Comp className={cn(buttonVariants({ variant, size }), className)} type={asChild ? undefined : type ?? 'button'} {...props} /> }
