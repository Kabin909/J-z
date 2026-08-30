import React, { forwardRef } from 'react';
import { Form } from 'formik';
import styled from 'styled-components/macro';
import FlashMessageRender from '@/components/FlashMessageRender';

const Container = styled.div`
    width: min(94vw, 560px);
    margin: 0 auto;
`;

export default forwardRef<HTMLFormElement, React.DetailedHTMLProps<React.FormHTMLAttributes<HTMLFormElement>, HTMLFormElement> & { title?: string }>(
    ({ title, ...props }, ref) => (
        <Container>
            <div className={'jz-auth-brand'}>
                <img src={'/images/jz-logo.png'} alt={'J&Z Panel'} />
                <div>
                    <div className={'jz-auth-name'}>J&Z <span>Panel</span></div>
                    <div className={'jz-auth-tagline'}>Premium game server control</div>
                </div>
            </div>
            <div className={'jz-auth-card'}>
                <div className={'jz-auth-heading'}>
                    <div className={'jz-auth-emoji'}>👋</div>
                    <div>
                        <h1>{title || 'Welcome back'}</h1>
                        <p>Sign in to your J&Z Panel account.</p>
                    </div>
                </div>
                <FlashMessageRender className={'mb-4'} />
                <Form {...props} ref={ref}>
                    {props.children}
                </Form>
            </div>
            <p className={'jz-auth-footer'}>&copy; 2015 - {new Date().getFullYear()} J&Z Panel · Secure hosting control</p>
        </Container>
    )
);
